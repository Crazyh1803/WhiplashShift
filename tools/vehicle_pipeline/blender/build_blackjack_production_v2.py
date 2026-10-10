import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path("/home/crazyh/Documents/ChatGPT/Whiplash Shift")
MODEL_DIR = ROOT / "godot/assets/vehicles/models/blackjack"
SCRIPT_DIR = ROOT / "tools/vehicle_pipeline/blender"
BLEND_PATH = SCRIPT_DIR / "blackjack_production_v2.blend"
GLB_PATH = MODEL_DIR / "blackjack_production_v2.glb"
LOD_PATH = MODEL_DIR / "blackjack_production_v2_lod1.glb"
QA_PATH = MODEL_DIR / "blackjack_production_v2_qa.json"
REF_SIDE = MODEL_DIR / "blackjack_realistic_candidate_v2.png"
REF_RUGGED = MODEL_DIR / "blackjack_rugged_front.png"
REF_INTERCEPTOR = MODEL_DIR / "blackjack_interceptor_front.png"
RENDERS = {
    "side": MODEL_DIR / "blackjack_production_v2_side.png",
    "three_quarter": MODEL_DIR / "blackjack_production_v2_three_quarter.png",
    "rugged_front": MODEL_DIR / "blackjack_production_v2_rugged_front.png",
    "interceptor_front": MODEL_DIR / "blackjack_production_v2_interceptor_front.png",
}
MODEL_DIR.mkdir(parents=True, exist_ok=True)


def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection, do_unlink=True)
    result = {}
    for name in ("BODY_EXPORT", "GAMEPLAY_EXPORT", "LOD1_EXPORT", "PREVIEW", "REFERENCES", "CUTTERS"):
        collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
        result[name] = collection
    return result


COL = reset_scene()
BODY = COL["BODY_EXPORT"]
PREVIEW = COL["PREVIEW"]
CUTTERS = COL["CUTTERS"]


def relink(obj, collection):
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)
    return obj


def material(name, color, metallic=0.0, roughness=0.5, transmission=0.0, emission=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Transmission Weight" in bsdf.inputs:
        bsdf.inputs["Transmission Weight"].default_value = transmission
    if transmission:
        bsdf.inputs["IOR"].default_value = 1.46
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 2.0
    return mat


MAT = {
    "Paint_Primary": material("Paint_Primary", (0.30, 0.36, 0.39), 0.72, 0.22),
    "Paint_Secondary": material("Paint_Secondary", (0.055, 0.070, 0.080), 0.68, 0.28),
    "Paint_Accent": material("Paint_Accent", (0.82, 0.23, 0.035), 0.62, 0.25),
    "Glass": material("Glass", (0.012, 0.035, 0.047), 0.05, 0.08, 0.38),
    "Mirror": material("Mirror", (0.58, 0.66, 0.70), 0.98, 0.035),
    "Rubber": material("Rubber", (0.008, 0.010, 0.012), 0.0, 0.88),
    "Grille": material("Grille", (0.010, 0.013, 0.015), 0.30, 0.78),
    "Lights": material("Lights", (0.64, 0.82, 0.94), 0.04, 0.10, 0.0, (0.45, 0.72, 1.0)),
    "Gunmetal": material("Gunmetal", (0.045, 0.052, 0.058), 0.92, 0.29),
    "BrushedMetal": material("BrushedMetal", (0.38, 0.42, 0.44), 0.94, 0.24),
    "ArmorProtected": material("ArmorProtected", (0.13, 0.15, 0.15), 0.78, 0.36),
}


def mesh_object(name, vertices, faces, mat, collection=BODY):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate(verbose=False)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    if mat:
        mesh.materials.append(mat)
    return obj


def smooth(obj):
    if obj.type == "MESH":
        for poly in obj.data.polygons:
            poly.use_smooth = True


def bevel(obj, width=0.006, segments=2):
    modifier = obj.modifiers.new("EdgeSupport", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    return modifier


def apply_modifier(obj, modifier):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    try:
        result = bpy.ops.object.modifier_apply(modifier=modifier.name)
        if "FINISHED" not in result:
            raise RuntimeError(f"modifier failed: {obj.name}/{modifier.name}")
    finally:
        obj.select_set(False)


PROFILE_KEYS = [
    # x, bottom, half width, belt, shoulder, roof, roof half width
    (-1.08, -0.275, 0.285, 0.06, 0.19, 0.30, 0.205),
    (-1.01, -0.295, 0.345, 0.14, 0.30, 0.43, 0.275),
    (-0.90, -0.305, 0.375, 0.20, 0.39, 0.53, 0.315),
    (-0.72, -0.305, 0.380, 0.23, 0.43, 0.56, 0.335),
    (-0.48, -0.305, 0.378, 0.23, 0.43, 0.56, 0.335),
    (-0.26, -0.305, 0.365, 0.21, 0.40, 0.52, 0.315),
    (-0.10, -0.305, 0.350, 0.17, 0.34, 0.45, 0.285),
    (0.04, -0.305, 0.342, 0.10, 0.25, 0.34, 0.255),
    (0.16, -0.305, 0.350, 0.09, 0.22, 0.31, 0.255),
    (0.30, -0.305, 0.365, 0.11, 0.24, 0.34, 0.270),
    (0.46, -0.305, 0.382, 0.09, 0.22, 0.30, 0.265),
    (0.60, -0.305, 0.390, 0.02, 0.14, 0.17, 0.245),
    (0.76, -0.292, 0.382, -0.01, 0.10, 0.115, 0.220),
    (0.92, -0.270, 0.345, -0.045, 0.055, 0.065, 0.170),
    (1.04, -0.235, 0.270, -0.085, -0.015, 0.005, 0.100),
    (1.08, -0.210, 0.205, -0.12, -0.065, -0.045, 0.055),
]


def profile_at(x):
    for index in range(len(PROFILE_KEYS) - 1):
        a, b = PROFILE_KEYS[index], PROFILE_KEYS[index + 1]
        if a[0] <= x <= b[0]:
            t = (x - a[0]) / (b[0] - a[0])
            t = t * t * (3.0 - 2.0 * t)
            return tuple(a[i] * (1.0 - t) + b[i] * t for i in range(1, 7))
    return PROFILE_KEYS[0][1:] if x < PROFILE_KEYS[0][0] else PROFILE_KEYS[-1][1:]


def section_points(x):
    bottom, width, belt, shoulder, roof, roof_width = profile_at(x)
    crown = 0.015 + 0.022 * max(0.0, min(1.0, (roof - belt) / 0.30))
    half = [
        (0.0, bottom + 0.002),
        (width * 0.55, bottom),
        (width * 0.88, bottom + 0.025),
        (width, bottom + 0.105),
        (width, belt - 0.05),
        (width * 0.985, belt),
        (width * 0.955, shoulder),
        (roof_width, roof - 0.025),
        (roof_width * 0.55, roof + crown * 0.55),
        (0.0, roof + crown),
    ]
    points = [(x, y, z) for z, y in half]
    points.extend((x, y, -z) for z, y in reversed(half[1:-1]))
    return points


def build_shell():
    xs = [-1.08 + 2.16 * i / 32.0 for i in range(33)]
    rings = [section_points(x) for x in xs]
    count = len(rings[0])
    vertices = [vertex for ring in rings for vertex in ring]
    faces = []
    for ring in range(len(rings) - 1):
        a = ring * count
        b = (ring + 1) * count
        for point in range(count):
            nxt = (point + 1) % count
            faces.append((a + point, a + nxt, b + nxt, b + point))
    faces.append(tuple(reversed(range(count))))
    last = (len(rings) - 1) * count
    faces.append(tuple(last + i for i in range(count)))
    obj = mesh_object("Body_MainShell", vertices, faces, MAT["ArmorProtected"])
    smooth(obj)
    sub = obj.modifiers.new("AutomotiveSubdivision", "SUBSURF")
    sub.subdivision_type = "CATMULL_CLARK"
    sub.levels = 2
    sub.render_levels = 2
    if hasattr(sub, "uv_smooth"):
        sub.uv_smooth = "PRESERVE_BOUNDARIES"
    bevel(obj, 0.006, 2)
    return obj


shell = build_shell()


def add_arch_cutters(obj):
    for x in (-0.66, -0.28, 0.66):
        radius = 0.215 if x < 0.0 else 0.205
        for side in (-1, 1):
            bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=radius, depth=0.30,
                                                location=(x, -0.205, side * 0.315))
            cutter = bpy.context.object
            cutter.name = f"Cutter_WheelArch_{x}_{side}"
            relink(cutter, CUTTERS)
            cutter.hide_render = True
            cutter.display_type = "WIRE"
            modifier = obj.modifiers.new(f"WheelArch_{x}_{side}", "BOOLEAN")
            modifier.operation = "DIFFERENCE"
            modifier.solver = "EXACT"
            modifier.object = cutter


add_arch_cutters(shell)


def curved_panel(name, grid, mat, solid=0.004, bevel_width=0.003):
    rows = len(grid)
    cols = len(grid[0])
    vertices = [v for row in grid for v in row]
    faces = []
    for row in range(rows - 1):
        for col in range(cols - 1):
            a = row * cols + col
            faces.append((a, a + 1, a + cols + 1, a + cols))
    obj = mesh_object(name, vertices, faces, mat)
    smooth(obj)
    if solid:
        mod = obj.modifiers.new("PanelThickness", "SOLIDIFY")
        mod.thickness = solid
        mod.offset = 0.0
    if bevel_width:
        bevel(obj, bevel_width, 2)
    return obj


def side_panel(name, x0, x1, y0, y1, side, mat, bulge=0.006):
    grid = []
    for row in range(4):
        y = y0 + (y1 - y0) * row / 3.0
        line = []
        for col in range(7):
            x = x0 + (x1 - x0) * col / 6.0
            width = profile_at(x)[1]
            bow = math.sin(math.pi * col / 6.0) * math.sin(math.pi * row / 3.0) * bulge
            line.append((x, y, side * (width + 0.018 + bow)))
        grid.append(line)
    return curved_panel(name, grid, mat)


for side, suffix in ((-1, "L"), (1, "R")):
    side_panel(f"Body_ArmoredDoor_{suffix}", -0.79, -0.39, 0.04, 0.18, side, MAT["Paint_Primary"])
    side_panel(f"Body_SidePanel_{suffix}", -0.36, -0.13, 0.04, 0.35, side, MAT["Paint_Primary"])
    side_panel(f"Body_InterceptorDoor_{suffix}", 0.18, 0.51, 0.02, 0.10, side, MAT["Paint_Primary"], 0.010)


def top_panel(name, x0, x1, z0, z1, mat, height_offset=0.022):
    grid = []
    for row in range(5):
        z = z0 + (z1 - z0) * row / 4.0
        line = []
        for col in range(8):
            x = x0 + (x1 - x0) * col / 7.0
            roof = profile_at(x)[4]
            crown = 0.015 * (1.0 - (z / max(abs(z0), abs(z1))) ** 2)
            line.append((x, roof + height_offset + crown, z))
        grid.append(line)
    return curved_panel(name, grid, mat)


top_panel("Body_ArmoredRoof", -0.82, -0.24, -0.28, 0.28, MAT["Paint_Secondary"])
top_panel("Body_CenterTransition", -0.23, 0.13, -0.25, 0.25, MAT["Paint_Accent"])
top_panel("Body_InterceptorRoof", 0.17, 0.48, -0.22, 0.22, MAT["Paint_Secondary"])
top_panel("Body_InterceptorHood", 0.55, 0.99, -0.26, 0.26, MAT["Paint_Primary"], 0.026)


def box(name, location, dimensions, mat, rotation=(0.0, 0.0, 0.0), collection=BODY, bevel_width=0.004):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.name = name
    relink(obj, collection)
    obj.data.materials.append(mat)
    if bevel_width:
        bevel(obj, bevel_width, 2)
    return obj


def cylinder_between(name, start, end, radius, mat, vertices=16, collection=BODY):
    start, end = Vector(start), Vector(end)
    delta = end - start
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=delta.length)
    obj = bpy.context.object
    obj.location = (start + end) * 0.5
    obj.rotation_euler = delta.to_track_quat("Z", "Y").to_euler()
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.name = name
    relink(obj, collection)
    obj.data.materials.append(mat)
    bevel(obj, min(radius * 0.25, 0.004), 2)
    smooth(obj)
    return obj


def tube(name, points, radius, mat, collection=BODY, cyclic=False):
    curve = bpy.data.curves.new(name + "Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, coordinate in zip(spline.points, points):
        point.co = (*coordinate, 1.0)
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    curve.materials.append(mat)
    return obj


def rivet(name, location, collection=BODY):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, radius=0.0065, location=location)
    obj = bpy.context.object
    obj.name = name
    relink(obj, collection)
    obj.data.materials.append(MAT["BrushedMetal"])
    return obj


# Real arch lips and wheel-well liners, shaped as open upper semicircles.
for x in (-0.66, -0.28, 0.66):
    radius = 0.215 if x < 0.0 else 0.205
    for side in (-1, 1):
        points = []
        for step in range(17):
            angle = math.radians(8.0 + 164.0 * step / 16.0)
            points.append((x + radius * math.cos(angle), -0.205 + radius * math.sin(angle), side * 0.365))
        tube(f"Armor_ArchLip_{x}_{side}", points, 0.009, MAT["ArmorProtected"])
        liner = list((px, py, side * 0.335) for px, py, _ in points)
        tube(f"Armor_WellLiner_{x}_{side}", liner, 0.018, MAT["ArmorProtected"])


# Armored end glazing, grille, lamps, door hardware, rivets, mirrors and exhaust.
for side in (-1, 1):
    side_panel(f"Glass_ArmoredSide_{side}", -0.78, -0.43, 0.21, 0.40, side, MAT["Glass"], 0.002)
    box(f"Glass_ArmoredWindshield_{side}", (-1.102, 0.335, side * 0.145),
        (0.020, 0.205, 0.255), MAT["Glass"], rotation=(0.0, 0.0, math.radians(-4)), bevel_width=0.010)
    box(f"Light_RuggedUpper_{side}", (-1.108, 0.055, side * 0.235), (0.025, 0.075, 0.105), MAT["Lights"], bevel_width=0.012)
    box(f"Light_RuggedLower_{side}", (-1.108, -0.035, side * 0.235), (0.025, 0.065, 0.105), MAT["Lights"], bevel_width=0.012)
    box(f"Door_Handle_Rugged_{side}", (-0.49, 0.08, side * 0.386), (0.055, 0.014, 0.014), MAT["Gunmetal"])
    for y in (0.00, 0.18):
        box(f"Door_Hinge_Rugged_{side}_{y}", (-0.79, y, side * 0.386), (0.026, 0.045, 0.018), MAT["BrushedMetal"])
    cylinder_between(f"MirrorBracket_Rugged_{side}", (-0.83, 0.29, side * 0.35), (-0.83, 0.30, side * 0.45), 0.008, MAT["BrushedMetal"])
    box(f"Mirror_Rugged_{side}", (-0.83, 0.30, side * 0.465), (0.09, 0.14, 0.025), MAT["Mirror"], bevel_width=0.015)
    for x in (-0.78, -0.67, -0.56, -0.45, -0.34, -0.23):
        rivet(f"Rivet_Rugged_{side}_{x}", (x, 0.475, side * 0.345))

box("Grille_RuggedRecess", (-1.105, 0.065, 0.0), (0.025, 0.205, 0.34), MAT["Grille"], bevel_width=0.008)
for z in (-0.135, -0.09, -0.045, 0.0, 0.045, 0.09, 0.135):
    box(f"Grille_RuggedSlat_{z}", (-1.120, 0.065, z), (0.018, 0.19, 0.012), MAT["BrushedMetal"], bevel_width=0.002)
box("Armor_RuggedBumper", (-1.112, -0.17, 0.0), (0.085, 0.10, 0.69), MAT["ArmorProtected"], bevel_width=0.018)
box("Windshield_RuggedCenterPillar", (-1.116, 0.335, 0.0), (0.018, 0.235, 0.024), MAT["ArmorProtected"], bevel_width=0.004)
cylinder_between("Windshield_RuggedHeader", (-1.118, 0.445, -0.29), (-1.118, 0.445, 0.29), 0.011, MAT["ArmorProtected"])
cylinder_between("Windshield_RuggedSill", (-1.118, 0.225, -0.29), (-1.118, 0.225, 0.29), 0.011, MAT["ArmorProtected"])
cylinder_between("Rubber_WindshieldSealTop", (-1.121, 0.435, -0.28), (-1.121, 0.435, 0.28), 0.006, MAT["Rubber"])
cylinder_between("Rubber_WindshieldSealBottom", (-1.121, 0.235, -0.28), (-1.121, 0.235, 0.28), 0.006, MAT["Rubber"])
for y in (-0.18, -0.08, 0.11):
    cylinder_between(f"BrushGuard_H_{y}", (-1.13, y, -0.36), (-1.13, y, 0.36), 0.014, MAT["BrushedMetal"])
for z in (-0.275, 0.275):
    cylinder_between(f"BrushGuard_V_{z}", (-1.13, -0.21, z), (-1.13, 0.15, z), 0.014, MAT["BrushedMetal"])
    cylinder_between(f"BrushGuard_Mount_{z}", (-1.08, -0.16, z), (-1.13, -0.16, z), 0.022, MAT["Gunmetal"])
box("Vent_RuggedRoof", (-0.55, 0.585, 0.0), (0.22, 0.04, 0.22), MAT["Grille"], bevel_width=0.012)
cylinder_between("Exhaust_Stack", (-0.16, 0.20, 0.29), (-0.16, 0.58, 0.29), 0.019, MAT["BrushedMetal"], 20)
cylinder_between("Exhaust_Mount", (-0.16, 0.25, 0.29), (-0.16, 0.25, 0.34), 0.027, MAT["Gunmetal"], 16)
cylinder_between("Exhaust_Tip", (-0.16, 0.58, 0.29), (-0.10, 0.62, 0.29), 0.020, MAT["BrushedMetal"], 20)


# Interceptor glass, fenders, recessed lighting, air dam, guns and mirrors.
top_panel("Glass_InterceptorWindshield", 0.43, 0.57, -0.255, 0.255, MAT["Glass"], 0.030)
for side in (-1, 1):
    side_panel(f"Glass_InterceptorSide_{side}", 0.19, 0.46, 0.13, 0.25, side, MAT["Glass"], 0.003)
    # Fender shoulder is a curved strip tied directly to the arch crown.
    grid = []
    for row in range(4):
        y = -0.205 + (0.165 + 0.035 * row / 3.0)
        line = []
        for col in range(9):
            a = math.radians(18 + 144 * col / 8.0)
            x = 0.66 + 0.208 * math.cos(a)
            yy = -0.205 + 0.208 * math.sin(a) + 0.012 * row
            line.append((x, max(y, yy), side * (0.382 + 0.006 * row)))
        grid.append(line)
    curved_panel(f"Armor_InterceptorFender_{side}", grid, MAT["ArmorProtected"], 0.004, 0.002)
    box(f"Light_InterceptorPair_{side}", (1.098, -0.015, side * 0.175), (0.035, 0.058, 0.135), MAT["Lights"], bevel_width=0.018)
    box(f"Gun_Recess_{side}", (1.096, 0.050, side * 0.082), (0.045, 0.065, 0.085), MAT["Grille"], bevel_width=0.010)
    for barrel in (-1, 1):
        cylinder_between(f"Gun_Barrel_{side}_{barrel}", (1.10, 0.050 + barrel * 0.014, side * 0.082),
                         (1.20, 0.050 + barrel * 0.014, side * 0.082), 0.007, MAT["Gunmetal"], 16)
    cylinder_between(f"MirrorBracket_Interceptor_{side}", (0.47, 0.18, side * 0.30),
                     (0.49, 0.18, side * 0.39), 0.007, MAT["BrushedMetal"])
    box(f"Mirror_Interceptor_{side}", (0.50, 0.19, side * 0.405), (0.09, 0.055, 0.045), MAT["Mirror"], bevel_width=0.018)
box("Grille_InterceptorAirDam", (1.097, -0.115, 0.0), (0.03, 0.075, 0.29), MAT["Grille"], bevel_width=0.014)
box("Armor_InterceptorSplitter", (1.105, -0.195, 0.0), (0.12, 0.025, 0.55), MAT["ArmorProtected"], bevel_width=0.008)


def add_reference(name, path, location, rotation, size):
    if not path.exists():
        raise RuntimeError(f"missing reference: {path}")
    bpy.ops.object.empty_add(type="IMAGE", location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data = bpy.data.images.load(str(path), check_existing=True)
    obj.empty_display_size = size
    obj.color[3] = 0.42
    obj.hide_render = True
    relink(obj, COL["REFERENCES"])


add_reference("Reference_Side_Calibrated", REF_SIDE, (0.0, 0.08, -0.52), (0.0, 0.0, 0.0), 2.16)
add_reference("Reference_RuggedFront_Calibrated", REF_RUGGED, (-1.30, 0.05, 0.0), (0.0, math.pi / 2.0, 0.0), 0.76)
add_reference("Reference_InterceptorFront_Calibrated", REF_INTERCEPTOR, (1.30, 0.02, 0.0), (0.0, -math.pi / 2.0, 0.0), 0.76)


def preview_wheel(x, side):
    radius = 0.178 if x > 0 else 0.185
    z = side * 0.405
    bpy.ops.mesh.primitive_torus_add(major_radius=radius * 0.77, minor_radius=radius * 0.23,
                                    major_segments=36, minor_segments=12, location=(x, -0.205, z))
    tire = bpy.context.object
    tire.name = f"Preview_Tire_{x}_{side}"
    relink(tire, PREVIEW)
    tire.data.materials.append(MAT["Rubber"])
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=radius * 0.57, depth=0.055,
                                       location=(x, -0.205, z))
    rim = bpy.context.object
    rim.name = f"Preview_Rim_{x}_{side}"
    relink(rim, PREVIEW)
    rim.data.materials.append(MAT["BrushedMetal"])
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=radius * 0.42, depth=0.061,
                                       location=(x, -0.205, z))
    brake = bpy.context.object
    brake.name = f"Preview_Brake_{x}_{side}"
    relink(brake, PREVIEW)
    brake.data.materials.append(MAT["Gunmetal"])


for wheel_x in (-0.66, -0.28, 0.66):
    for wheel_side in (-1, 1):
        preview_wheel(wheel_x, wheel_side)
for wheel_x in (-0.66, -0.28, 0.66):
    cylinder_between(f"Preview_Axle_{wheel_x}", (wheel_x, -0.205, -0.39), (wheel_x, -0.205, 0.39),
                     0.025, MAT["Gunmetal"], 20, PREVIEW)
box("Preview_Supercharger", (0.70, 0.155, 0.0), (0.18, 0.12, 0.18), MAT["Gunmetal"], collection=PREVIEW, bevel_width=0.014)
for side in (-1, 1):
    cylinder_between(f"Preview_SuperchargerScoop_{side}", (0.68, 0.19, side * 0.05),
                     (0.78, 0.19, side * 0.05), 0.025, MAT["BrushedMetal"], 18, PREVIEW)


def smart_uv(obj):
    if obj.type != "MESH" or not obj.data.polygons:
        return
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.018, area_weight=0.25)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)


for obj in BODY.all_objects:
    if obj.type == "MESH":
        smart_uv(obj)


def bake_collection(source, target, lod_ratio=None):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for source_obj in source.all_objects:
        if source_obj.type not in {"MESH", "CURVE"}:
            continue
        evaluated = source_obj.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
        obj = bpy.data.objects.new(source_obj.name, mesh)
        obj.matrix_world = source_obj.matrix_world.copy()
        target.objects.link(obj)
        existing_materials = {m.name for m in mesh.materials if m is not None}
        for mat in source_obj.data.materials:
            if mat is not None and mat.name not in existing_materials:
                mesh.materials.append(mat)
                existing_materials.add(mat.name)
        smooth(obj)
        smart_uv(obj)
        if lod_ratio is not None and len(mesh.polygons) > 48:
            decimate = obj.modifiers.new("LOD1_Decimate", "DECIMATE")
            decimate.ratio = lod_ratio
            decimate.use_collapse_triangulate = True
            apply_modifier(obj, decimate)


bake_collection(BODY, COL["GAMEPLAY_EXPORT"])
bake_collection(COL["GAMEPLAY_EXPORT"], COL["LOD1_EXPORT"], 0.46)


def triangle_count(collection):
    total = 0
    vertices = 0
    for obj in collection.all_objects:
        if obj.type == "MESH":
            obj.data.calc_loop_triangles()
            total += len(obj.data.loop_triangles)
            vertices += len(obj.data.vertices)
    return vertices, total


def export_collection(collection, path):
    rotation = Matrix.Rotation(math.radians(90.0), 4, "X")
    originals = {}
    bpy.ops.object.select_all(action="DESELECT")
    for obj in collection.all_objects:
        originals[obj.name_full] = obj.matrix_world.copy()
        obj.matrix_world = rotation @ obj.matrix_world
        obj.select_set(True)
    active = next((obj for obj in collection.all_objects if obj.type == "MESH"), None)
    if active is None:
        raise RuntimeError(f"no export mesh in {collection.name}")
    bpy.context.view_layer.objects.active = active
    result = bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                                       export_apply=True, export_materials="EXPORT", export_cameras=False,
                                       export_lights=False)
    for obj in collection.all_objects:
        obj.matrix_world = originals[obj.name_full]
        obj.select_set(False)
    if "FINISHED" not in result or not path.exists():
        raise RuntimeError(f"GLB export failed: {path}")


# Preview studio. Ground is XZ because the authored vehicle uses Y-up.
box("Preview_Ground", (0.0, -0.395, 0.0), (5.0, 0.025, 5.0), MAT["ArmorProtected"], collection=PREVIEW, bevel_width=0.0)


def aim(obj, target=(0.0, 0.0, 0.0)):
    forward = (Vector(target) - obj.location).normalized()
    world_up = Vector((0.0, 1.0, 0.0))
    right = forward.cross(world_up).normalized()
    up = right.cross(forward).normalized()
    obj.rotation_euler = Matrix((right, up, -forward)).transposed().to_euler()


camera_data = bpy.data.cameras.new("QACamera")
camera = bpy.data.objects.new("QACamera", camera_data)
PREVIEW.objects.link(camera)
camera_data.type = "ORTHO"
bpy.context.scene.camera = camera
for name, location, energy, size in (
    ("Key", (1.5, 3.5, 2.7), 1100.0, 3.2),
    ("Fill", (2.5, 1.2, -2.5), 720.0, 3.0),
    ("Rim", (-2.5, 2.5, 1.5), 900.0, 2.6),
):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    light = bpy.data.objects.new(name, data)
    light.location = location
    aim(light)
    PREVIEW.objects.link(light)


scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1024
scene.render.resolution_y = 768
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.world.use_nodes = True
background = scene.world.node_tree.nodes.get("Background")
background.inputs["Color"].default_value = (0.055, 0.065, 0.075, 1.0)
background.inputs["Strength"].default_value = 0.38


def render(path, location, target, ortho):
    camera.location = location
    camera.data.ortho_scale = ortho
    aim(camera, target)
    scene.render.filepath = str(path)
    result = bpy.ops.render.render(write_still=True)
    if "FINISHED" not in result or not path.exists():
        raise RuntimeError(f"render failed: {path}")


render(RENDERS["side"], (0.0, 0.08, 3.6), (0.0, 0.04, 0.0), 2.50)
render(RENDERS["three_quarter"], (2.8, 1.15, 3.0), (0.02, 0.02, 0.0), 2.55)
render(RENDERS["rugged_front"], (-3.5, 0.18, 0.0), (-0.45, 0.02, 0.0), 1.25)
render(RENDERS["interceptor_front"], (3.5, 0.10, 0.0), (0.55, -0.03, 0.0), 1.20)


# Save the editable high-detail source with references, modifiers and preview rig intact.
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
game_vertices, game_triangles = triangle_count(COL["GAMEPLAY_EXPORT"])
lod_vertices, lod_triangles = triangle_count(COL["LOD1_EXPORT"])
if not 20000 <= game_triangles <= 40000:
    raise RuntimeError(f"gameplay triangle budget failed: {game_triangles}")
if not 7000 <= lod_triangles <= 18000:
    raise RuntimeError(f"LOD1 triangle budget failed: {lod_triangles}")
export_collection(COL["GAMEPLAY_EXPORT"], GLB_PATH)
export_collection(COL["LOD1_EXPORT"], LOD_PATH)

report = {
    "vehicle": "Blackjack X-17",
    "generator": "Blender 5.2.2 blueprint-traced continuous-cage builder",
    "source": str(BLEND_PATH),
    "gameplay": {"path": str(GLB_PATH), "objects": len(COL["GAMEPLAY_EXPORT"].all_objects),
                 "vertices": game_vertices, "triangles": game_triangles},
    "lod1": {"path": str(LOD_PATH), "objects": len(COL["LOD1_EXPORT"].all_objects),
             "vertices": lod_vertices, "triangles": lod_triangles},
    "materials": sorted(MAT.keys()),
    "references": [str(REF_SIDE), str(REF_RUGGED), str(REF_INTERCEPTOR)],
    "renders": {key: str(value) for key, value in RENDERS.items()},
    "physics_changed": False,
}
QA_PATH.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(f"BLACKJACK_V2_EXPORT objects={len(COL['GAMEPLAY_EXPORT'].all_objects)} triangles={game_triangles} lod1={lod_triangles} glb={GLB_PATH}")
