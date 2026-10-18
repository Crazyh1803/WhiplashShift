"""Scene finalisation, GLB/LOD export and QA renders for the Knifeedge candidate."""

import bpy

import knifeedge_core as C
import knifeedge_qa as Q
import knifeedge_trace as T

QA_DIR_NAME = "qa/knifeedge_blueprint"
SEMANTIC = ("Knifeedge_Paint", "Knifeedge_Secondary", "Knifeedge_Stripe")


def source_meshes(cols):
    return [o for o in cols["KNIFEEDGE_SOURCE"].objects if o.type == "MESH"]


def finalize_scene(cols, hull, blueprint):
    for obj in source_meshes(cols):
        if not obj.data.uv_layers:
            C.smart_uv(obj)
    image = bpy.data.images.load(str(blueprint), check_existing=True)
    image.pack()
    ref = bpy.data.objects.new("Reference_HotWheels_Blueprint", None)
    ref.empty_display_type = "IMAGE"
    ref.data = image
    ref.empty_display_size = 5.0
    ref.hide_render = True
    ref.hide_viewport = True
    cols["REFERENCE"].objects.link(ref)
    hull["vehicle_id"] = "knifeedge"
    hull["design"] = "Knifeedge XR: supercar nose (End A +X) / sand-rail spaceframe (End B -X)"
    hull["blueprint"] = "hot-wheels.jpg"
    hull["wheelbase"] = T.WHEELBASE
    hull["scale_m_per_px"] = T.SCALE
    for name in ("CUTTERS", "REFERENCE"):
        cols[name].hide_render = True
        cols[name].hide_viewport = True
    bpy.context.scene.unit_settings.system = "METRIC"


def _is_wheel(obj):
    return obj.name.startswith(("Wheel_Truck_", "Wheel_Coupe_"))


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


LOD1_DROP = ("Fine_HeadFin", "Fine_HoodLouvre", "Fine_TailSlat", "Fine_DoorHandle", "Fine_Badge", "Fine_MufflerMount",
             "Fine_ShockSpring", "Fine_WinchFlange")
LOD2_KEEP = ("Fine_TailLamp", "Fine_LedStrip", "Fine_RoofLamp")


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
        if name.startswith("Body_Cage"):
            if level == 2:
                _decimate(obj, 0.5)
        elif name.startswith("Body_"):
            if level:
                _decimate(obj, (0.70, 0.45)[level - 1])
        elif name.startswith("Glass_"):
            pass
        elif _is_wheel(obj):
            if level and ("_Tire_" in name or "_Rim_" in name):
                _decimate(obj, (0.50, 0.28)[level - 1])
            # spokes and wire bundles are never decimated: collapsing them drops a wheel part (LOD2 lost one)
        elif name.startswith("Prop_"):
            if level == 2:
                _decimate(obj, 0.6)
        else:
            if name.startswith("Trim_") and level:
                _decimate(obj, (0.6, 0.45)[level - 1])
            key = obj.data.materials[0].name
            groups.setdefault(key, []).append(obj)
    for key, objs in sorted(groups.items()):
        _join(objs, "Detail_" + key.replace("Knifeedge_", ""), col)
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
    for view in ("side", "top", "front_truck", "front_coupe", "three_quarter_truck", "three_quarter_coupe",
                 "far_side_three_quarter", "truck_detail", "coupe_detail", "wheel_truck", "wheel_coupe", "engine",
                 "cockpit", "roof", "underside"):
        if views and view not in views:
            continue
        Q.configure(view, 1280, 720)
        Q.render(out_dir / f"{stem}_{view}.png")
    for view in ("side", "top"):
        if views and view + "_overlay" not in views:
            continue
        Q.overlay(view, blueprint, out_dir / f"{stem}_{view}_overlay.png")
    print("AK: rendered " + str(out_dir))
