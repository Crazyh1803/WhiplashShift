"""Scene, material and mesh helpers shared by the Knifeedge hard-surface builders."""
import math

import bmesh
import bpy
from mathutils.bvhtree import BVHTree


def reset_scene():
    """Remove every datablock so repeated runs produce identical names."""
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for blocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras,
                   bpy.data.lights, bpy.data.images, bpy.data.worlds):
        for item in list(blocks):
            blocks.remove(item)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)
    cols = {}
    for name in ("KNIFEEDGE_SOURCE", "CUTTERS", "REFERENCE", "STUDIO", "EXPORT_GAMEPLAY",
                 "EXPORT_LOD1", "EXPORT_LOD2"):
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
        cols[name] = col
    return cols


def make_material(name, color, metallic=0.0, roughness=0.5, coat=0.0, coat_rough=0.05,
                  emission=None, emission_strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if coat:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = coat_rough
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    mat.diffuse_color = (*color, 1.0)
    return mat


def build_materials():
    """Three semantic paint channels plus fixed glass, rubber, steel, iron and light materials."""
    return {
        "paint": make_material("Knifeedge_Paint", (0.060, 0.230, 0.420), 0.35, 0.28, 0.8, 0.04),
        "paint2": make_material("Knifeedge_Secondary", (0.78, 0.84, 0.90), 0.30, 0.34, 0.6, 0.05),
        "accent": make_material("Knifeedge_Stripe", (0.90, 0.30, 0.025), 0.25, 0.36, 0.5, 0.06),
        "glass": make_material("Knifeedge_Glass", (0.020, 0.040, 0.055), 0.10, 0.03, 1.0, 0.0),
        "rubber": make_material("Knifeedge_Rubber", (0.020, 0.020, 0.022), 0.0, 0.85),
        "steel": make_material("Knifeedge_Steel", (0.62, 0.65, 0.68), 1.0, 0.22),
        "iron": make_material("Knifeedge_Iron", (0.035, 0.038, 0.042), 0.85, 0.45),
        "lamp": make_material("Knifeedge_Lamp", (0.90, 0.92, 0.85), 0.05, 0.10,
                              emission=(1.0, 0.95, 0.80), emission_strength=3.0),
    }


class Builder:
    """Owns collections/materials and creates linked mesh objects."""

    def __init__(self, cols, mats):
        self.cols = cols
        self.mats = mats
        self.slots = {}

    def link(self, obj, col="KNIFEEDGE_SOURCE"):
        for owner in list(obj.users_collection):
            owner.objects.unlink(obj)
        self.cols[col].objects.link(obj)
        return obj

    def mesh_object(self, name, verts, faces, mat_keys, face_mats=None, col="KNIFEEDGE_SOURCE",
                    location=(0, 0, 0), smooth=True):
        """verts/faces in object-local space; mat_keys is the slot list."""
        mesh = bpy.data.meshes.new(name + "_mesh")
        mesh.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
        mesh.validate(verbose=False)
        mesh.update()
        for key in mat_keys:
            mesh.materials.append(self.mats[key])
        if face_mats is not None:
            for poly, index in zip(mesh.polygons, face_mats):
                poly.material_index = index
        for poly in mesh.polygons:
            poly.use_smooth = smooth
        obj = bpy.data.objects.new(name, mesh)
        obj.location = location
        self.cols[col].objects.link(obj)
        return obj


def bm_to_object(builder, name, bm, mat_keys, col="KNIFEEDGE_SOURCE", location=(0, 0, 0),
                 smooth=False):
    mesh = bpy.data.meshes.new(name + "_mesh")
    bm.to_mesh(mesh)
    bm.free()
    for key in mat_keys:
        mesh.materials.append(builder.mats[key])
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    builder.cols[col].objects.link(obj)
    return obj


def recalc_normals(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def evaluated_mesh(obj, apply_world=True):
    """Return a standalone evaluated mesh (caller removes it)."""
    deps = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(deps), depsgraph=deps)
    if apply_world:
        mesh.transform(obj.matrix_world)
    return mesh


def bvh_of(mesh):
    return BVHTree.FromPolygons([v.co.copy() for v in mesh.vertices],
                                [tuple(p.vertices) for p in mesh.polygons])


def apply_all_modifiers(obj):
    deps = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(deps), depsgraph=deps)
    old = obj.data
    obj.modifiers.clear()
    obj.data = mesh
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return obj


def triangle_count(objs):
    total = 0
    deps = bpy.context.evaluated_depsgraph_get()
    for obj in objs:
        if obj.type != "MESH":
            continue
        ev = obj.evaluated_get(deps)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        total += len(me.loop_triangles)
        ev.to_mesh_clear()
    return total


def smart_uv(obj, angle=66, margin=0.012):
    if obj.type != "MESH" or not obj.data.polygons:
        return
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)


def harden(obj, angle_deg=32.0, keep_flat=False):
    """Smooth-shade curved surfaces but split normals at creases sharper than angle."""
    if obj.type != "MESH":
        return
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    limit = math.radians(angle_deg)
    for edge in bm.edges:
        if len(edge.link_faces) == 2:
            edge.smooth = edge.calc_face_angle(0.0) < limit
        else:
            edge.smooth = False
    if not keep_flat:
        for face in bm.faces:
            face.smooth = True
    bm.to_mesh(mesh)
    bm.free()
    if hasattr(mesh, "use_auto_smooth"):
        mesh.use_auto_smooth = True
        mesh.auto_smooth_angle = math.pi


def repair_manifold(obj, distances=(0.0005, 0.001, 0.002, 0.004)):
    """Weld only the neighbourhood of open edges (sub-pixel needles from Booleans)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for distance in distances:
        bad = {v for e in bm.edges if not e.is_manifold for v in e.verts}
        if not bad:
            break
        bmesh.ops.remove_doubles(bm, verts=list(bad), dist=distance)
        bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=0.00005)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    open_edges = sum(1 for e in bm.edges if not e.is_manifold)
    volume = bm.calc_volume(signed=True)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return open_edges, volume


def dissolve_flat(obj, angle_deg=0.8):
    """Merge near-coplanar faces of equal material to cut triangle count, deterministically.

    BMesh's priority-based dissolve_limit varies between runs, so select edges by a pure
    function of the geometry and dissolve that fixed set (edge order = mesh order).
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    limit = math.radians(angle_deg)
    flat = []
    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        f0, f1 = e.link_faces
        if f0.material_index != f1.material_index or f0.smooth != f1.smooth:
            continue
        if e.calc_face_angle(math.pi) < limit:
            flat.append(e)
    bmesh.ops.dissolve_edges(bm, edges=flat, use_verts=True, use_face_split=False)
    open_edges = sum(1 for e in bm.edges if not e.is_manifold)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return open_edges


def boolean_difference(obj, cutter):
    """Exact boolean obj - cutter, applied; the cutter object is removed afterwards."""
    mod = obj.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cutter
    apply_all_modifiers(obj)
    mesh = cutter.data
    bpy.data.objects.remove(cutter, do_unlink=True)
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)
    return obj
