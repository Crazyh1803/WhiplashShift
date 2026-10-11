"""Build the Deadbolt reversible truck/Mustang from its orthographic blueprint.

The script is intentionally self-contained and idempotent. Run it headlessly with
Blender; it replaces the scene, packs the reference sheet, and saves the source.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SOURCE_BLUEPRINT = (Path(argv[0]).expanduser().resolve() if argv else
                    ROOT / "tools/vehicle_pipeline/references/80sFord.jpg")
MODEL_DIR = ROOT / "godot/assets/vehicles/models/deadbolt"
BLEND_PATH = ROOT / "tools/vehicle_pipeline/blender/deadbolt_blueprint.blend"
REPORT_PATH = MODEL_DIR / "deadbolt_blueprint_build.json"
MODEL_DIR.mkdir(parents=True, exist_ok=True)


def reset_scene():
    # Hidden reference empties are not reliably selectable. Removing every
    # object datablock keeps repeated runs exact-name idempotent.
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                       bpy.data.cameras, bpy.data.lights, bpy.data.images):
        for item in list(datablocks):
            datablocks.remove(item)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)
    result = {}
    for name in ("DEADBOLT_SOURCE", "REFERENCE", "LIGHTING"):
        collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
        result[name] = collection
    return result


COL = reset_scene()
BODY = COL["DEADBOLT_SOURCE"]


def material(name, color, metallic=0.0, roughness=0.5, transmission=0.0,
             emission=None):
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
        bsdf.inputs["Emission Strength"].default_value = 3.0
    return mat


MAT = {
    "paint": material("Deadbolt_Paint", (0.065, 0.115, 0.145), 0.72, 0.24),
    "paint2": material("Deadbolt_Secondary", (0.16, 0.20, 0.22), 0.62, 0.30),
    "accent": material("Deadbolt_Stripe", (0.74, 0.12, 0.035), 0.55, 0.28),
    "glass": material("Deadbolt_Glass", (0.012, 0.035, 0.052), 0.10, 0.08, 0.35),
    "rubber": material("Deadbolt_Rubber", (0.008, 0.010, 0.011), 0.0, 0.86),
    "metal": material("Deadbolt_BrushedMetal", (0.34, 0.38, 0.40), 0.92, 0.22),
    "dark": material("Deadbolt_Gunmetal", (0.025, 0.032, 0.038), 0.82, 0.34),
    "grille": material("Deadbolt_Grille", (0.010, 0.013, 0.015), 0.35, 0.72),
    "headlight": material("Deadbolt_Headlight", (0.55, 0.76, 0.92), 0.08, 0.12,
                          emission=(0.38, 0.68, 1.0)),
    "taillight": material("Deadbolt_Marker", (0.62, 0.025, 0.008), 0.12, 0.18,
                          emission=(0.8, 0.02, 0.005)),
}


def link_active(obj, collection=BODY):
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)
    return obj


def apply_bevel(obj, width=0.025, segments=2):
    mod = obj.modifiers.new("ProductionEdgeSupport", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    return obj


def shade(obj):
    if obj.type == "MESH":
        for poly in obj.data.polygons:
            poly.use_smooth = True
    return obj


def box(name, location, dimensions, mat, rotation=(0.0, 0.0, 0.0), bevel=0.02):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = link_active(bpy.context.object)
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel:
        apply_bevel(obj, bevel, 2)
    return obj


def mesh_object(name, vertices, faces, mat):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate(verbose=False)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    BODY.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def tube(name, points, radius, mat, cyclic=False):
    curve = bpy.data.curves.new(name + "Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for dst, src in zip(spline.points, points):
        dst.co = (*src, 1.0)
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, curve)
    BODY.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def panel(name, points, mat, thickness=0.012, bevel=0.01):
    obj = mesh_object(name, points, [(0, 1, 2, 3)], mat)
    solid = obj.modifiers.new("PanelThickness", "SOLIDIFY")
    solid.thickness = thickness
    solid.offset = 0.0
    if bevel:
        apply_bevel(obj, bevel, 2)
    return obj


# x, floor, half-width, belt, shoulder, roof, roof half-width.  The left end is
# the upright truck nose; the right end is the low Mustang-derived nose.
PROFILE = [
    (-2.48, 0.36, 0.73, 0.78, 0.92, 1.18, 0.58),
    (-2.30, 0.27, 0.85, 0.80, 0.98, 1.27, 0.66),
    (-1.90, 0.24, 0.91, 0.76, 0.92, 1.18, 0.66),
    (-1.35, 0.22, 0.92, 0.79, 0.97, 1.40, 0.70),
    (-0.95, 0.21, 0.91, 0.83, 1.03, 1.54, 0.69),
    (-0.48, 0.20, 0.90, 0.86, 1.08, 1.62, 0.66),
    (-0.05, 0.19, 0.90, 0.84, 1.05, 1.56, 0.65),
    (0.36, 0.18, 0.92, 0.76, 0.96, 1.38, 0.69),
    (0.82, 0.17, 0.94, 0.69, 0.85, 1.19, 0.67),
    (1.28, 0.16, 0.95, 0.61, 0.73, 0.94, 0.62),
    (1.72, 0.15, 0.94, 0.53, 0.64, 0.72, 0.54),
    (2.16, 0.17, 0.88, 0.46, 0.55, 0.59, 0.40),
    (2.48, 0.24, 0.71, 0.40, 0.47, 0.49, 0.24),
]


def ring(p):
    x, floor, width, belt, shoulder, roof, roof_width = p
    crown = 0.025
    half = [
        (0.0, floor),
        (width * 0.72, floor - 0.01),
        (width, floor + 0.11),
        (width, belt),
        (width * 0.96, shoulder),
        (roof_width, roof - 0.03),
        (0.0, roof + crown),
    ]
    pts = [(x, y, z) for y, z in half]
    pts.extend((x, -y, z) for y, z in reversed(half[1:-1]))
    return pts


def build_shell():
    rings = [ring(p) for p in PROFILE]
    count = len(rings[0])
    vertices = [v for r in rings for v in r]
    faces = []
    for ri in range(len(rings) - 1):
        a, b = ri * count, (ri + 1) * count
        for j in range(count):
            faces.append((a + j, a + (j + 1) % count,
                          b + (j + 1) % count, b + j))
    faces.append(tuple(reversed(range(count))))
    last = (len(rings) - 1) * count
    faces.append(tuple(last + i for i in range(count)))
    obj = mesh_object("Body_DeadboltUnifiedShell", vertices, faces, MAT["paint"])
    shade(obj)
    sub = obj.modifiers.new("AutomotiveSurface", "SUBSURF")
    sub.subdivision_type = "CATMULL_CLARK"
    sub.levels = 2
    sub.render_levels = 2
    apply_bevel(obj, 0.015, 2)
    return obj


shell = build_shell()


def side_details(side):
    suffix = "L" if side > 0 else "R"
    y = side * 0.925
    # Truck door, coupe door and the intentionally visible reversible seam.
    panel(f"Panel_TruckDoor_{suffix}", [(-1.25, y, 0.49), (-0.45, y, 0.48),
          (-0.39, y, 1.24), (-1.08, y, 1.37)], MAT["paint2"], 0.018)
    panel(f"Glass_TruckSide_{suffix}", [(-1.08, y + side * 0.015, 0.93),
          (-0.48, y + side * 0.015, 0.93), (-0.52, side * 0.72, 1.43),
          (-0.97, side * 0.72, 1.43)], MAT["glass"], 0.008, 0.006)
    panel(f"Glass_CoupeSide_{suffix}", [(-0.34, y + side * 0.014, 0.91),
          (0.90, y + side * 0.014, 0.78), (0.53, side * 0.72, 1.27),
          (-0.29, side * 0.72, 1.43)], MAT["glass"], 0.008, 0.006)
    panel(f"Panel_CoupeDoor_{suffix}", [(-0.31, y, 0.43), (0.83, y, 0.38),
          (0.91, y, 0.77), (-0.33, y, 0.89)], MAT["paint"], 0.018)
    # Rocker rail visually joins both halves.
    box(f"Detail_Rocker_{suffix}", (-0.08, side * 0.955, 0.29),
        (3.58, 0.075, 0.10), MAT["dark"], bevel=0.018)
    box(f"Detail_TruckHandle_{suffix}", (-0.58, side * 0.966, 0.88),
        (0.16, 0.025, 0.035), MAT["metal"], bevel=0.012)
    box(f"Detail_CoupeHandle_{suffix}", (0.44, side * 0.969, 0.73),
        (0.14, 0.025, 0.030), MAT["metal"], bevel=0.010)
    # Orange identity stripe anchors the car at gameplay distance.
    panel(f"Livery_ReversibleSlash_{suffix}", [(0.00, y + side * 0.024, 0.39),
          (0.66, y + side * 0.024, 0.36), (0.47, y + side * 0.024, 0.48),
          (-0.16, y + side * 0.024, 0.50)], MAT["accent"], 0.006, 0.004)


for side in (-1, 1):
    side_details(side)

# Roof glass and center spine communicate the shared cockpit from above.
panel("Glass_Roof", [(-0.78, -0.54, 1.535), (-0.78, 0.54, 1.535),
      (0.33, 0.51, 1.35), (0.33, -0.51, 1.35)], MAT["glass"], 0.010, 0.008)
box("Detail_RoofSpine", (-0.19, 0.0, 1.47), (1.45, 0.075, 0.055), MAT["dark"],
    rotation=(0.0, -0.13, 0.0), bevel=0.018)

# Truck end: broad square grille, sealed-beam lights and a functional brush bar.
box("Truck_Grille", (-2.455, 0.0, 0.72), (0.075, 1.34, 0.47), MAT["grille"], bevel=0.035)
for y in (-0.55, -0.18, 0.18, 0.55):
    box(f"Truck_GrilleBar_{y:+.2f}", (-2.502, y, 0.72), (0.035, 0.035, 0.40), MAT["metal"], bevel=0.008)
for y in (-0.63, 0.63):
    box(f"Truck_Headlight_{y:+.2f}", (-2.515, y, 0.84), (0.05, 0.26, 0.20), MAT["headlight"], bevel=0.035)
    box(f"Truck_Marker_{y:+.2f}", (-2.515, y, 0.59), (0.05, 0.22, 0.08), MAT["taillight"], bevel=0.018)
tube("Truck_BrushGuard", [(-2.61, -0.78, 0.31), (-2.66, -0.78, 0.93),
     (-2.66, 0.78, 0.93), (-2.61, 0.78, 0.31)], 0.038, MAT["metal"])
tube("Truck_Bumper", [(-2.62, -0.82, 0.34), (-2.68, 0.0, 0.30),
     (-2.62, 0.82, 0.34)], 0.055, MAT["dark"])

# Coupe end: narrow Mustang-inspired lamps, center intake, splitter and hood vents.
box("Coupe_Grille", (2.475, 0.0, 0.34), (0.06, 1.05, 0.19), MAT["grille"], bevel=0.025)
for y in (-0.57, 0.57):
    box(f"Coupe_Headlight_{y:+.2f}", (2.49, y, 0.47), (0.045, 0.42, 0.115), MAT["headlight"],
        bevel=0.025)
box("Coupe_Splitter", (2.43, 0.0, 0.18), (0.36, 1.72, 0.075), MAT["dark"], bevel=0.018)
for y in (-0.29, 0.29):
    box(f"Coupe_HoodVent_{y:+.2f}", (1.72, y, 0.69), (0.48, 0.18, 0.035), MAT["grille"],
        rotation=(0.0, -0.18, 0.0), bevel=0.018)

# Side mirrors face both directions and read as a reversible vehicle cue.
for x in (-1.03, 0.76):
    for side in (-1, 1):
        box(f"Mirror_{x:+.2f}_{side:+d}", (x, side * 1.03, 0.99), (0.18, 0.12, 0.10),
            MAT["metal"], rotation=(0.0, 0.0, side * 0.12), bevel=0.035)
        tube(f"MirrorStem_{x:+.2f}_{side:+d}", [(x, side * 0.91, 0.93),
             (x, side * 1.00, 0.98)], 0.018, MAT["dark"])


def wheel(name, x, radius, coupe_style=False):
    width = 0.29 if coupe_style else 0.34
    for side in (-1, 1):
        y = side * 0.91
        bpy.ops.mesh.primitive_torus_add(major_radius=radius * 0.77,
            minor_radius=radius * 0.23, major_segments=36, minor_segments=10,
            location=(x, y, radius))
        tire = link_active(bpy.context.object)
        tire.name = f"Wheel_{name}_Tire_{side:+d}"
        tire.rotation_euler.x = math.pi / 2
        bpy.context.view_layer.objects.active = tire
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        tire.dimensions = (radius * 2, width, radius * 2)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        tire.data.materials.append(MAT["rubber"])
        shade(tire)
        bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=radius * 0.63,
            depth=width * 1.04, location=(x, y, radius))
        rim = link_active(bpy.context.object)
        rim.name = f"Wheel_{name}_Rim_{side:+d}"
        rim.rotation_euler.x = math.pi / 2
        bpy.context.view_layer.objects.active = rim
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        rim.data.materials.append(MAT["metal"])
        apply_bevel(rim, 0.012, 2)
        spoke_count = 10 if coupe_style else 6
        for index in range(spoke_count):
            angle = math.tau * index / spoke_count
            spoke = box(f"Wheel_{name}_Spoke_{side:+d}_{index}",
                (x, y + side * (width * 0.54), radius),
                (radius * 0.76, 0.025, radius * (0.055 if coupe_style else 0.085)),
                MAT["dark"], rotation=(0.0, angle, 0.0), bevel=0.008)
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=radius * 0.17,
            depth=width * 1.10, location=(x, y, radius))
        hub = link_active(bpy.context.object)
        hub.name = f"Wheel_{name}_Hub_{side:+d}"
        hub.rotation_euler.x = math.pi / 2
        bpy.context.view_layer.objects.active = hub
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        hub.data.materials.append(MAT["dark"])
        apply_bevel(hub, 0.01, 2)


wheel("Truck", -1.72, 0.43, False)
wheel("Coupe", 1.66, 0.40, True)

# Raised fender lips preserve the two distinct wheel openings without fragile booleans.
for x, radius, label in ((-1.72, 0.49, "Truck"), (1.66, 0.46, "Coupe")):
    samples = 14
    for side in (-1, 1):
        pts = [(x + radius * math.cos(math.pi * i / samples),
                side * 0.955, radius + radius * math.sin(math.pi * i / samples))
               for i in range(samples + 1)]
        tube(f"FenderLip_{label}_{side:+d}", pts, 0.032, MAT["paint2"])

# Simple underbody armor is visible between the very different end treatments.
box("Underbody_Center", (0.0, 0.0, 0.19), (3.55, 1.48, 0.12), MAT["dark"], bevel=0.035)
for x in (-1.72, 1.66):
    tube(f"Axle_{x:+.2f}", [(x, -0.94, 0.43 if x < 0 else 0.40),
         (x, 0.94, 0.43 if x < 0 else 0.40)], 0.045, MAT["dark"])

# Pack the original sheet in the native source without exposing it in renders.
if not SOURCE_BLUEPRINT.is_file():
    raise FileNotFoundError(f"Missing blueprint: {SOURCE_BLUEPRINT}")
image = bpy.data.images.load(str(SOURCE_BLUEPRINT), check_existing=True)
image.pack()
reference = bpy.data.objects.new("Reference_80sFord_Blueprint", None)
reference.empty_display_type = "IMAGE"
reference.data = image
reference.empty_display_size = 5.0
reference.hide_render = True
reference.hide_viewport = True
COL["REFERENCE"].objects.link(reference)

# Source metadata travels with the blend and exported asset.
shell["vehicle_id"] = "deadbolt"
shell["design"] = "reversible 80s Ford truck / Mustang coupe"
shell["blueprint"] = "80sFord.jpg"
shell["wheelbase"] = 3.38
shell["length"] = 5.16
shell["width"] = 2.06
shell["height"] = 1.65

scene = bpy.context.scene
render_engines = {
    item.identifier
    for item in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items
}
scene.render.engine = ("BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in render_engines
                       else "BLENDER_EEVEE")
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.world.color = (0.018, 0.022, 0.028)

# Convert curve details to meshes so the GLB and LOD helpers see the complete asset.
for obj in list(BODY.objects):
    if obj.type == "CURVE":
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.convert(target="MESH")
        obj.select_set(False)

for obj in BODY.objects:
    obj.select_set(False)
    if obj.type == "MESH" and not obj.data.uv_layers:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
        bpy.ops.object.mode_set(mode="OBJECT")
        obj.select_set(False)

bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), check_existing=False)

triangles = 0
for obj in BODY.objects:
    if obj.type == "MESH":
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
report = {
    "vehicle_id": "deadbolt",
    "source": str(BLEND_PATH.relative_to(ROOT)),
    "blueprint": str(SOURCE_BLUEPRINT.relative_to(ROOT)),
    "blueprint_packed": bool(image.packed_file),
    "mesh_objects": sum(1 for obj in BODY.objects if obj.type == "MESH"),
    "source_triangles_before_export_modifiers": triangles,
    "dimensions_m": {"length": 5.16, "width": 2.06, "height": 1.65},
    "materials": sorted(mat.name for mat in bpy.data.materials),
}
REPORT_PATH.write_text(json.dumps(report, indent=2) + "\n")
print("AK: " + json.dumps(report), flush=True)
