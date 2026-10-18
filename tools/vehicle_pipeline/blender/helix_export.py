"""Scene finalisation, GLB/LOD export and QA renders for the Helix candidate."""

import bmesh
import bpy

import helix_core as C
import helix_qa as Q
import helix_trace as T

QA_DIR_NAME = "qa/helix_blueprint"
SEMANTIC = ("Helix_Paint", "Helix_Secondary", "Helix_Stripe")


def source_meshes(cols):
    return [o for o in cols["HELIX_SOURCE"].objects if o.type == "MESH"]


def finalize_scene(cols, hull, blueprint):
    for obj in source_meshes(cols):
        if not obj.data.uv_layers:
            C.smart_uv(obj)
    image = bpy.data.images.load(str(blueprint), check_existing=True)
    image.pack()
    ref = bpy.data.objects.new("Reference_RType_Blueprint", None)
    ref.empty_display_type = "IMAGE"
    ref.data = image
    ref.empty_display_size = 5.0
    ref.hide_render = True
    ref.hide_viewport = True
    cols["REFERENCE"].objects.link(ref)
    hull["vehicle_id"] = "helix"
    hull["design"] = "Helix Wraith: hovering R-9 style nose (End A +X) / biomechanical tracked claw rig (End B -X)"
    hull["blueprint"] = "r-type.jpg"
    hull["scale_m_per_px"] = T.SCALE
    for name in ("CUTTERS", "REFERENCE"):
        cols[name].hide_render = True
        cols[name].hide_viewport = True
    bpy.context.scene.unit_settings.system = "METRIC"


def _copy(obj, col):
    new = obj.copy()
    new.data = obj.data.copy()
    col.objects.link(new)
    return new


def _decimate(obj, ratio):
    if len(obj.data.polygons) < 24:
        return
    mod = obj.modifiers.new("lod", "DECIMATE")
    mod.ratio = ratio
    mod.use_collapse_triangulate = False
    C.apply_all_modifiers(obj)
    C.harden(obj, 35.0)


def _split_materials(obj, col):
    """Move faces of every material but slot 0 into separate undecimated objects (name + _mN)."""
    out = []
    mats = list(obj.data.materials)
    for idx in range(1, len(mats)):
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        keep = [f for f in bm.faces if f.material_index != idx]
        bmesh.ops.delete(bm, geom=keep, context="FACES")
        if bm.faces:
            mesh = bpy.data.meshes.new(f"{obj.name}_m{idx}_mesh")
            bm.to_mesh(mesh)
            for m in mats:
                mesh.materials.append(m)
            piece = bpy.data.objects.new(f"{obj.name}_m{idx}", mesh)
            piece.matrix_world = obj.matrix_world
            col.objects.link(piece)
            out.append(piece)
        bm.free()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index != 0], context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    return out


def _join(objs, name, col):
    if not objs:
        return None
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    spare = [o.data for o in objs[1:]]
    bpy.ops.object.join()
    for mesh in spare:
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name + "_mesh"
    return joined


LOD1_DROP = ("Fine_ClawTeeth", "Fine_Gills", "Fine_SpineSlots", "Fine_HoseFlanges", "Fine_ClawPivotB",
             "Fine_Bolts")
LOD2_KEEP = ("Fine_NacelleLens", "Fine_PodLens")
DECIMATE = {"Body_Hull": (0.62, 0.34), "Body_Plate": (0.6, 0.38), "Body_Hose": (0.6, 0.34),
            "Body_Claw": (0.6, 0.38), "Body_Collar": (0.55, 0.30), "Body_Shoulder": (0.55, 0.3),
            "Body_Fender": (0.6, 0.35), "Body_Pod": (0.6, 0.35), "Body_Nacelle": (0.6, 0.35),
            "Body_Wing": (1.0, 1.0)}


def build_export_set(cols, level):
    """Copy source meshes into EXPORT_* with merged small details. level: 0, 1, 2."""
    col = cols[["EXPORT_GAMEPLAY", "EXPORT_LOD1", "EXPORT_LOD2"][level]]
    for o in list(col.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    groups = {}
    for src in source_meshes(cols):
        name = src.name
        if (name.startswith("Fine_") and not name.startswith(LOD2_KEEP)
                and (level == 2 or (level == 1 and name.startswith(LOD1_DROP)))):
            continue  # dropped before copying so no orphan mesh datablock is created
        obj = _copy(src, col)
        for m in list(obj.modifiers):
            obj.modifiers.remove(m)
        if level and name.startswith("Body_") and len(obj.data.materials) > 1:
            _split_materials(obj, col)  # keep thin paint-channel bands out of the decimation
        if name.startswith(("Body_", "Trim_")):
            key = next((k for k in DECIMATE if name.startswith(k)), None)
            if level and key:
                _decimate(obj, DECIMATE[key][level - 1])
            if name.startswith("Trim_"):
                groups.setdefault(obj.data.materials[0].name, []).append(obj)
        elif name.startswith(("Glass_", "Frame_", "Prop_Track_")):
            pass  # tracks stay whole in every LOD (cleats/teeth must not vanish)
        else:
            groups.setdefault(obj.data.materials[0].name, []).append(obj)
    for key, objs in sorted(groups.items()):
        _join(objs, "Detail_" + key.replace("Helix_", ""), col)
    return col


def triangles_of(col):
    return C.triangle_count([o for o in col.objects if o.type == "MESH"])


def export_collection(col, path):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    objs = [o for o in col.objects if o.type == "MESH"]
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                              export_apply=True)
    return path.stat().st_size


def export_all(cols, model_dir, stem):
    result = {}
    sizes = {}
    for level, rel in ((0, f"{stem}.glb"), (1, f"lod/{stem}_LOD1.glb"), (2, f"lod/{stem}_LOD2.glb")):
        col = build_export_set(cols, level)
        tris = triangles_of(col)
        sizes[f"lod{level}"] = {"triangles": tris, "objects": len(col.objects),
                                "bytes": export_collection(col, model_dir / rel)}
        for o in list(col.objects):
            data = o.data
            bpy.data.objects.remove(o, do_unlink=True)
            if data.users == 0:
                bpy.data.meshes.remove(data)
        col.hide_render = True
    result["exports"] = sizes
    return result


def render_qa(cols, model_dir, stem, blueprint, views=None):
    out_dir = model_dir.parents[4] / "tools/vehicle_pipeline" / QA_DIR_NAME
    out_dir.mkdir(parents=True, exist_ok=True)
    Q.build_studio(cols)
    for view in Q.VIEWS:
        if views and view not in views:
            continue
        Q.configure(view, 1280, 720)
        Q.render(out_dir / f"{stem}_{view}.png")
    for view in ("side", "top"):
        if views and view + "_overlay" not in views:
            continue
        Q.overlay(view, blueprint, out_dir / f"{stem}_{view}_overlay.png")
    print("AK: rendered " + str(out_dir))
