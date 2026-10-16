import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path("/home/crazyh/Documents/ChatGPT/Whiplash Shift")
MODEL_DIR = ROOT / "godot/assets/vehicles/models/blackjack"
BLEND_PATH = ROOT / "tools/vehicle_pipeline/blender/blackjack_production.blend"
GLB_PATH = MODEL_DIR / "blackjack_production.glb"
PREVIEWS = {
    "side": MODEL_DIR / "blackjack_production_side.png",
    "three_quarter": MODEL_DIR / "blackjack_production_three_quarter.png",
    "rugged_front": MODEL_DIR / "blackjack_production_rugged_front.png",
    "interceptor_front": MODEL_DIR / "blackjack_production_interceptor_front.png",
}
MODEL_DIR.mkdir(parents=True, exist_ok=True)
BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)


def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection, do_unlink=True)
    export = bpy.data.collections.new("BODY_EXPORT")
    preview = bpy.data.collections.new("PREVIEW")
    bpy.context.scene.collection.children.link(export)
    bpy.context.scene.collection.children.link(preview)
    return export, preview


EXPORT, PREVIEW = reset_scene()


def pbr(name, color, metallic=0.0, roughness=0.5, emission=None):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.8
    return material


MAT = {
    "body": pbr("BodyPrimer", (0.52, 0.55, 0.57), 0.45, 0.34),
    "armor": pbr("ArmorDark", (0.11, 0.13, 0.13), 0.72, 0.38),
    "glass": pbr("Glass", (0.008, 0.025, 0.035), 0.12, 0.08),
    "trim": pbr("TrimBlack", (0.012, 0.015, 0.017), 0.15, 0.72),
    "metal": pbr("BrushedMetal", (0.38, 0.42, 0.44), 0.92, 0.24),
    "grille": pbr("GrilleBlack", (0.008, 0.010, 0.011), 0.35, 0.82),
    "head": pbr("Headlight", (0.62, 0.78, 0.90), 0.05, 0.10, (0.4, 0.65, 1.0)),
    "tail": pbr("TailLight", (0.42, 0.008, 0.004), 0.05, 0.16, (0.8, 0.01, 0.0)),
    "gun": pbr("Gunmetal", (0.055, 0.065, 0.07), 0.90, 0.30),
    "rubber": pbr("PreviewRubber", (0.008, 0.010, 0.012), 0.0, 0.90),
    "alloy": pbr("PreviewAlloy", (0.34, 0.38, 0.41), 0.95, 0.20),
}


def put(obj, collection=EXPORT):
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)
    return obj


def finish(obj, name, material, bevel=0.0, segments=2):
    obj.name = name
    put(obj)
    if material:
        obj.data.materials.append(material)
    if bevel > 0.0:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        modifier = obj.modifiers.new("ProductionBevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = segments
        modifier.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    return obj


def box(name, location, dimensions, material, rotation=(0.0, 0.0, 0.0), bevel=0.008):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, material, bevel)


def prism(name, sections, material, bevel=0.008):
    vertices = []
    faces = []
    for x, bottom, top, width in sections:
        vertices.extend([
            (x, bottom, -width), (x, bottom, width),
            (x, top, width), (x, top, -width),
        ])
    faces.append((0, 3, 2, 1))
    last = (len(sections) - 1) * 4
    faces.append((last, last + 1, last + 2, last + 3))
    for section in range(len(sections) - 1):
        a = section * 4
        b = (section + 1) * 4
        for edge in range(4):
            nxt = (edge + 1) % 4
            faces.append((a + edge, a + nxt, b + nxt, b + edge))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    EXPORT.objects.link(obj)
    return finish(obj, name, material, bevel)


def cylinder(name, start, end, radius, material, vertices=12):
    start = Vector(start)
    end = Vector(end)
    delta = end - start
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=delta.length)
    obj = bpy.context.object
    obj.location = (start + end) * 0.5
    obj.rotation_euler = delta.to_track_quat("Z", "Y").to_euler()
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, material, 0.002, 1)


def tube(name, points, radius, material, collection=EXPORT, cyclic=False):
    data = bpy.data.curves.new(name + "Curve", "CURVE")
    data.dimensions = "3D"
    data.resolution_u = 1
    data.bevel_depth = radius
    data.bevel_resolution = 2
    data.resolution_u = 1
    spline = data.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, coordinate in zip(spline.points, points):
        point.co = (*coordinate, 1.0)
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    data.materials.append(material)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    obj.select_set(False)
    if collection == EXPORT:
        put(obj, EXPORT)
    return obj


def rivet(name, location):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, radius=0.007, location=location)
    return finish(bpy.context.object, name, MAT["metal"], 0.0)


def arch(name, center_x, side_z):
    points = []
    for step in range(13):
        angle = math.radians(8.0 + step * 164.0 / 12.0)
        points.append((center_x + 0.175 * math.cos(angle), -0.205 + 0.175 * math.sin(angle), side_z))
    return tube(name, points, 0.012, MAT["trim"])


# Primary unified shell.
box("Body_ChassisSpine", (0.0, -0.205, 0.0), (1.88, 0.13, 0.50), MAT["body"], bevel=0.018)
prism("Body_ArmoredCab", [
    (-0.91, -0.12, 0.26, 0.31), (-0.78, -0.10, 0.39, 0.34),
    (-0.48, -0.10, 0.41, 0.34), (-0.12, -0.10, 0.40, 0.31),
], MAT["body"], 0.012)
prism("Body_ArmoredNose", [
    (-1.01, -0.17, 0.08, 0.30), (-0.94, -0.15, 0.18, 0.32),
    (-0.78, -0.12, 0.27, 0.33),
], MAT["body"], 0.010)
prism("Body_CenterTransition", [
    (-0.15, -0.11, 0.39, 0.31), (0.08, -0.10, 0.27, 0.30),
    (0.24, -0.11, 0.15, 0.29),
], MAT["body"], 0.010)
prism("Body_InterceptorCab", [
    (0.08, -0.11, 0.05, 0.29), (0.23, -0.10, 0.19, 0.30),
    (0.43, -0.10, 0.22, 0.29), (0.62, -0.11, 0.09, 0.28),
], MAT["body"], 0.010)
prism("Body_InterceptorNose", [
    (0.47, -0.14, 0.075, 0.31), (0.74, -0.14, 0.055, 0.29),
    (0.94, -0.135, 0.005, 0.255), (1.01, -0.13, -0.035, 0.23),
], MAT["body"], 0.008)

# Side skirts, underbody, and three wheel-arch stations.
for side in (-1, 1):
    z = side * 0.318
    box(f"Trim_SideRail_{side}", (0.0, -0.255, z), (1.76, 0.045, 0.035), MAT["metal"], bevel=0.007)
    for index, center in enumerate((-0.66, -0.28, 0.66)):
        arch(f"Trim_WheelArch_{side}_{index}", center, side * 0.334)
box("Detail_CenterFuelCell", (-0.01, -0.285, 0.0), (0.28, 0.10, 0.42), MAT["armor"], bevel=0.012)
box("Detail_LeftEquipmentBox", (-0.13, -0.18, -0.34), (0.24, 0.18, 0.08), MAT["armor"], bevel=0.009)
box("Detail_RightEquipmentBox", (-0.13, -0.18, 0.34), (0.24, 0.18, 0.08), MAT["armor"], bevel=0.009)

# Armored cabin side panels, doors, glazing, hinges, handles, and rivets.
for side in (-1, 1):
    z = side * 0.343
    box(f"Body_VanDoor_{side}", (-0.55, 0.085, z), (0.34, 0.40, 0.014), MAT["body"], bevel=0.006)
    box(f"Glass_VanSide_{side}", (-0.57, 0.275, side * 0.351), (0.29, 0.145, 0.012), MAT["glass"], bevel=0.010)
    box(f"Body_RearDoor_{side}", (-0.25, 0.075, z), (0.20, 0.42, 0.014), MAT["body"], bevel=0.005)
    box(f"Glass_RearSide_{side}", (-0.25, 0.275, side * 0.351), (0.15, 0.13, 0.012), MAT["glass"], bevel=0.009)
    box(f"Trim_VanHandle_{side}", (-0.48, 0.075, side * 0.354), (0.055, 0.014, 0.014), MAT["trim"], bevel=0.004)
    for hinge_y in (-0.02, 0.15):
        box(f"Detail_Hinge_{side}_{hinge_y}", (-0.72, hinge_y, side * 0.354), (0.025, 0.045, 0.018), MAT["metal"], bevel=0.003)
    for x in (-0.73, -0.62, -0.51, -0.40, -0.31, -0.20):
        rivet(f"Detail_RivetTop_{side}_{x}", (x, 0.382, side * 0.351))
        rivet(f"Detail_RivetLow_{side}_{x}", (x, -0.095, side * 0.351))
    for y in (-0.04, 0.06, 0.16, 0.26, 0.35):
        rivet(f"Detail_RivetFront_{side}_{y}", (-0.82, y, side * 0.341))
        rivet(f"Detail_RivetRear_{side}_{y}", (-0.13, y, side * 0.316))

# Split armored windshield and frontal hardware.
for side in (-1, 1):
    box(f"Glass_ArmoredWindshield_{side}", (-0.922, 0.275, side * 0.145), (0.016, 0.155, 0.265), MAT["glass"], bevel=0.012)
    box(f"Light_ArmoredHeadlamp_{side}", (-1.026, -0.015, side * 0.215), (0.025, 0.075, 0.095), MAT["head"], bevel=0.012)
box("Grille_ArmoredMain", (-1.028, -0.025, 0.0), (0.022, 0.155, 0.31), MAT["grille"], bevel=0.003)
for index, z in enumerate((-0.13, -0.087, -0.043, 0.0, 0.043, 0.087, 0.13)):
    box(f"Grille_ArmoredSlat_{index}", (-1.043, -0.025, z), (0.018, 0.145, 0.012), MAT["metal"], bevel=0.002)
box("Armor_ArmoredBumper", (-1.035, -0.165, 0.0), (0.075, 0.095, 0.65), MAT["armor"], bevel=0.018)
for index, y in enumerate((-0.17, -0.075, 0.105)):
    cylinder(f"Detail_BrushBarH_{index}", (-1.083, y, -0.35), (-1.083, y, 0.35), 0.014, MAT["metal"])
for index, z in enumerate((-0.27, 0.27)):
    cylinder(f"Detail_BrushBarV_{index}", (-1.083, -0.20, z), (-1.083, 0.14, z), 0.014, MAT["metal"])

# Interceptor glass, door skins, handles, hood, lights, intakes, and weapon recesses.
box("Glass_InterceptorWindshield", (0.565, 0.145, 0.0), (0.19, 0.014, 0.52), MAT["glass"], rotation=(0.0, 0.0, math.radians(-50)), bevel=0.010)
for side in (-1, 1):
    z = side * 0.297
    box(f"Body_InterceptorDoor_{side}", (0.39, -0.005, z), (0.34, 0.20, 0.014), MAT["body"], bevel=0.007)
    box(f"Glass_InterceptorSide_{side}", (0.39, 0.115, side * 0.304), (0.30, 0.12, 0.012), MAT["glass"], bevel=0.012)
    box(f"Trim_InterceptorHandle_{side}", (0.34, -0.005, side * 0.308), (0.055, 0.012, 0.014), MAT["trim"], bevel=0.003)
box("Body_InterceptorHood", (0.77, 0.063, 0.0), (0.40, 0.018, 0.49), MAT["body"], rotation=(0.0, 0.0, math.radians(-8)), bevel=0.008)
box("Grille_InterceptorAirDam", (1.015, -0.105, 0.0), (0.024, 0.060, 0.245), MAT["grille"], bevel=0.008)
for side in (-1, 1):
    box(f"Light_InterceptorHeadlamp_{side}", (0.976, -0.015, side * 0.17), (0.035, 0.050, 0.125), MAT["head"], bevel=0.014)
    box(f"Gun_Recess_{side}", (0.962, 0.027, side * 0.085), (0.038, 0.055, 0.095), MAT["grille"], bevel=0.008)
    for barrel in (-1, 1):
        cylinder(
            f"Gun_Barrel_{side}_{barrel}",
            (0.965, 0.027 + barrel * 0.014, side * 0.085),
            (1.055, 0.027 + barrel * 0.014, side * 0.085),
            0.008, MAT["gun"], 12,
        )

# Transition details, exhaust, roof markers, armor vents.
box("Armor_CenterBackbone", (-0.04, 0.20, 0.0), (0.12, 0.39, 0.58), MAT["armor"], rotation=(0.0, 0.0, math.radians(-10)), bevel=0.010)
for side in (-1, 1):
    box(f"Grille_CenterVent_{side}", (-0.105, 0.19, side * 0.298), (0.08, 0.24, 0.014), MAT["grille"], bevel=0.004)
cylinder("Detail_ExhaustStack", (-0.13, 0.31, 0.27), (-0.13, 0.55, 0.27), 0.018, MAT["metal"], 14)
cylinder("Detail_ExhaustTip", (-0.13, 0.55, 0.27), (-0.08, 0.59, 0.27), 0.018, MAT["metal"], 14)
for index, z in enumerate((-0.19, -0.065, 0.065, 0.19)):
    box(f"Light_RoofMarker_{index}", (-0.55, 0.424, z), (0.035, 0.022, 0.035), MAT["tail"], bevel=0.006)


# Preview-only modular wheels, floor, cameras, and lighting.
def preview_wheel(x, side):
    z = side * 0.37
    radius = 0.155 if x > 0.3 else 0.165
    bpy.ops.mesh.primitive_torus_add(major_radius=radius * 0.78, minor_radius=radius * 0.22, major_segments=36, minor_segments=12, location=(x, -0.205, z))
    tire = bpy.context.object
    tire.data.materials.append(MAT["rubber"])
    put(tire, PREVIEW)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=radius * 0.56, depth=0.035, location=(x, -0.205, z))
    rim = bpy.context.object
    rim.data.materials.append(MAT["alloy"])
    put(rim, PREVIEW)
    for spoke_index in range(8):
        angle = spoke_index * math.tau / 8.0
        bpy.ops.mesh.primitive_cube_add(
            location=(x + math.cos(angle) * radius * 0.27, -0.205 + math.sin(angle) * radius * 0.27, z),
            rotation=(0.0, 0.0, angle),
        )
        spoke = bpy.context.object
        spoke.dimensions = (radius * 0.43, radius * 0.09, 0.046)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        spoke.data.materials.append(MAT["alloy"])
        put(spoke, PREVIEW)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=radius * 0.17, depth=0.052, location=(x, -0.205, z))
    hub = bpy.context.object
    hub.data.materials.append(MAT["gun"])
    put(hub, PREVIEW)


for wheel_x in (-0.66, -0.28, 0.66):
    for wheel_side in (-1, 1):
        preview_wheel(wheel_x, wheel_side)

bpy.ops.mesh.primitive_plane_add(size=12, location=(0.0, -0.375, 0.0))
ground = bpy.context.object
ground.data.materials.append(pbr("PreviewGround", (0.09, 0.10, 0.11), 0.0, 0.70))
put(ground, PREVIEW)


def aim(obj, target=(0.0, 0.0, 0.0)):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
    # Keep world Y vertical in the inspection frames. Blender's track quaternion
    # otherwise chooses a 90-degree roll for these X/Z-aligned views.
    obj.rotation_euler.rotate_axis("Z", math.radians(-90.0))


camera_data = bpy.data.cameras.new("PreviewCamera")
camera = bpy.data.objects.new("PreviewCamera", camera_data)
PREVIEW.objects.link(camera)
camera_data.type = "ORTHO"
bpy.context.scene.camera = camera

for name, location, energy, size in (
    ("Key", (0.2, 3.2, 2.7), 950.0, 4.0),
    ("Fill", (2.8, 1.2, -2.5), 650.0, 3.0),
    ("Rim", (-3.0, 2.2, 1.8), 800.0, 3.0),
):
    light_data = bpy.data.lights.new(name, "AREA")
    light_data.energy = energy
    light_data.shape = "DISK"
    light_data.size = size
    light = bpy.data.objects.new(name, light_data)
    light.location = location
    aim(light, (0.0, 0.0, 0.0))
    PREVIEW.objects.link(light)

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1024
scene.render.resolution_y = 768
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.render.image_settings.color_mode = "RGBA"
scene.world.use_nodes = True
background = scene.world.node_tree.nodes.get("Background")
background.inputs["Color"].default_value = (0.055, 0.065, 0.075, 1.0)
background.inputs["Strength"].default_value = 0.35


def render(path, location, target, ortho, extra_roll=0.0):
    camera.location = location
    camera.data.ortho_scale = ortho
    aim(camera, target)
    if extra_roll:
        camera.rotation_euler.rotate_axis("Z", math.radians(extra_roll))
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


render(PREVIEWS["side"], (0.0, 0.10, 3.6), (0.0, 0.0, 0.0), 2.35, -90.0)
render(PREVIEWS["three_quarter"], (2.7, 0.62, 3.0), (0.0, -0.02, 0.0), 2.45)
render(PREVIEWS["rugged_front"], (-3.2, 0.25, 0.0), (-0.35, 0.0, 0.0), 1.25)
render(PREVIEWS["interceptor_front"], (3.2, 0.18, 0.0), (0.35, -0.02, 0.0), 1.20)

# Save the editable source, then export only production body objects.
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
# Geometry above is intentionally authored in the project's X-length/Y-up/Z-width
# convention. Convert it to Blender's X-length/Z-up/-Y-width convention before
# glTF performs its own Z-up -> Y-up conversion. The resulting GLB arrives in
# Godot as X-length/Y-up/Z-width without changing the editable source scene.
export_basis = Matrix.Rotation(math.radians(90.0), 4, "X")
for obj in EXPORT.all_objects:
    obj.matrix_world = export_basis @ obj.matrix_world
bpy.ops.object.select_all(action="DESELECT")
for obj in EXPORT.all_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = next(obj for obj in EXPORT.all_objects if obj.type == "MESH")
bpy.ops.export_scene.gltf(
    filepath=str(GLB_PATH), export_format="GLB", use_selection=True,
    export_apply=True, export_materials="EXPORT",
)

triangles = 0
for obj in EXPORT.all_objects:
    if obj.type == "MESH":
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
print(f"BLACKJACK_EXPORT objects={len(EXPORT.all_objects)} triangles={triangles} glb={GLB_PATH}")
